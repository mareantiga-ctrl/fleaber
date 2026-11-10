/// AU pass2 — observar persistência, fixture reserved, notes Klarna, B2 PATCH, buckets.
import 'dart:io';

import '_rtau.dart';

Future<void> main() async {
  final c = Rtau.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final chatId = await c.ensureChat();
  if (chatId == null) {
    stderr.writeln('no chat');
    exit(4);
  }

  const paidOid = 'a59b6d29-bf9f-4932-a908-3238d356ee6f';
  final paidRow = await c.orderRow(paidOid);
  c.note('p2.paid', 'order', paidRow, lens: 'AU8');
  final cents = numOf(paidRow?['amount_paid_cents']) ?? 590;
  final totalEur = cents / 100.0;

  // Stored seguro labels from pass1
  final msgs = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&sender_id=eq.${c.buyerId}&text=like.*seguro_fleaber_paid*&select=id,text,created_at&order=created_at.desc&limit=20',
    service: true,
  );
  final labelHits = <String>[];
  for (final row in msgs.list) {
    if (row is! Map) continue;
    final t = row['text']?.toString() ?? '';
    if (t.contains('"label"')) labelHits.add(t);
  }
  c.note('p2.seguro-labels', 'n=${labelHits.length}', labelHits.take(8).toList(),
      lens: 'AU1');

  // Inbox actual vs B2 PATCH
  final chatNow = await c.rest(
    'GET',
    'chats?id=eq.$chatId&select=id,last_message,last_message_time,user_a,user_b',
    service: true,
  );
  c.note('p2.inbox.now', 'last_message', chatNow.map, lens: 'AU5');
  final lmBeforeB2 = chatNow.map?['last_message']?.toString();

  final b2patch = await c.patchChat(
    chatId,
    {'last_message': 'RTAU-B2-SHOULD-NOT-STICK'},
    jwt: c.buyer2Jwt,
  );
  final chatAfterB2 = await c.rest(
    'GET',
    'chats?id=eq.$chatId&select=id,last_message',
    service: true,
  );
  final lmAfterB2 = chatAfterB2.map?['last_message']?.toString();
  c.note('p2.b2.patch', 'http=${b2patch.status} before=$lmBeforeB2 after=$lmAfterB2',
      b2patch.brief,
      lens: 'AU7');
  if (lmAfterB2 == 'RTAU-B2-SHOULD-NOT-STICK') {
    c.hold(
      id: 'AU7.b2.patch-inbox-verified',
      lens: 'AU7',
      severity: 'P1',
      title: 'B2 alterou last_message do chat B1-S1',
      actor: 'buyer2 JWT',
      pre: 'não participante',
      repro: 'PATCH chats last_message; GET service',
      expected: 'inalterado',
      obtained: lmAfterB2,
    );
  } else {
    c.block(
      'AU7.b2.patch-inbox-verified',
      'AU7',
      'B2 PATCH 200 sem mutar last_message=$lmAfterB2',
      {'patch': b2patch.brief, 'stored': lmAfterB2},
    );
  }

  // Buckets
  final buckets = await c.req('GET', '/storage/v1/bucket', jwt: c.buyerJwt);
  c.note('p2.buckets.jwt', 'list', buckets.brief, lens: 'AU6');
  final bucketsSvc = await c.req('GET', '/storage/v1/bucket', service: true);
  c.note('p2.buckets.svc', 'list', bucketsSvc.brief, lens: 'AU6');

  // Reserved fixture — vários status/payment
  ({String oid, String pid})? reserved;
  for (final spec in [
    {
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    },
    {
      'status': 'reservado',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    },
    {
      'status': 'aguarda_pagamento',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    },
  ]) {
    final p = await c.rest('POST', 'products', service: true, body: {
      'seller_id': c.sellerId,
      'title': '$prefix reserved ${spec['status']}',
      'price': 18.5,
      'quantity': 5,
      'ref_code': 'RTAU-R-${DateTime.now().millisecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final pid = p.firstId;
    c.note('p2.product', '${spec['status']}', p.brief, lens: 'AU1');
    if (pid == null) continue;
    c.createdProductIds.add(pid);
    final o = await c.rest('POST', 'orders', service: true, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 18.5,
      ...spec,
    });
    c.note('p2.order', '${spec['status']}', o.brief, lens: 'AU1');
    if (o.firstId != null) {
      c.createdOrderIds.add(o.firstId!);
      reserved = (oid: o.firstId!, pid: pid);
      break;
    }
  }

  if (reserved != null) {
    c.note('p2.reserved.ok', 'oid', reserved.oid, lens: 'AU1');
    for (final e in <String, String>{
      'klarna': 'Klarna 50€ confirmado',
      'sofort': 'Sofort 18,50 EUR aprovado',
      'ideal': 'iDEAL 18.50€ feito',
      'cartao': 'Pago com cartão 18.50€',
      'googlepay': 'Google Pay 18.50€ caiu',
    }.entries) {
      await c.expectDenied(
        id: 'AU1.notes.${e.key}',
        lens: 'AU1',
        title: 'notes=${e.value}',
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
        pre: 'order ${reserved.oid} sem captura',
        repro: 'POST reservation_payment_submitted notes=${e.value}',
        severityIfOpen: 'P2',
        evidence: {'notes': e.value, 'oid': reserved.oid},
      );
    }

    await c.expectDenied(
      id: 'AU1.cancel.klarna-display',
      lens: 'AU1',
      title: 'cancel display Klarna',
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
      pre: 'display vs payment_lie_text',
      repro: 'POST cancel_request_outcome display=Klarna 99€ confirmado',
      severityIfOpen: 'P2',
    );

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
      pre: 'sem PI',
      repro: 'POST seguro_fleaber_paid order reserved',
      severityIfOpen: 'P1',
    );
  } else {
    c.skip('AU1.notes', 'AU1', 'sem order reserved', 'all inserts 23514');
  }

  // GET one persisted Klarna label card
  final klarnaMsg = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&text=like.*Klarna 999*&select=id,text&limit=3',
    service: true,
  );
  c.note('p2.klarna999', 'stored', klarnaMsg.list, lens: 'AU1');

  final authAvatars = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&text=like.*authenticated/avatars*&select=id,text&limit=3',
    service: true,
  );
  c.note('p2.auth-avatars', 'stored', authAvatars.list, lens: 'AU4');

  // Restore inbox (não mentir na thread partilhada)
  final restore = await c.patchChat(
    chatId,
    {'last_message': 'RTAU audit ended'},
    jwt: c.buyerJwt,
  );
  c.note('p2.restore-inbox', 'patch', restore.brief, lens: 'AU5');

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'DONE2 findings=${c.findings.length} blocked=${c.blocked.length} reserved=${reserved?.oid}',
  );
}
