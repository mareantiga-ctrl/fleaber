/// REDTEAM_BLIND_CE_CHAT_POS_BXCC_v1 — pass1 CE-A rails/copy + inbox.
/// Staging only. No fixes. Anti-atrofia: rails FORA do exacto BXCC.
import 'dart:convert';
import 'dart:io';

import '_rtce.dart';

Future<void> main() async {
  final c = Rtce.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final sku = await c.createProduct(title: '$prefix-cea', price: 12);
  if (sku == null) {
    stderr.writeln('no sku');
    exit(4);
  }
  final chatId = await c.ensureChat(sku);
  final oid = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    price: 12,
    payment: 'MB WAY',
  );
  final paid = await c.payToPago();
  if (chatId == null || oid == null || paid == null) {
    stderr.writeln('fixture fail chat=$chatId oid=$oid paid=$paid');
    exit(4);
  }
  final paidTotal = (paid.paidCents / 100).toStringAsFixed(2);

  Future<Map<String, dynamic>?> tryCard({
    required String id,
    required String lens,
    required Map<String, Object?> payload,
    String? title,
    String severity = 'P1',
    bool countIfPersist = true,
    String? jwt,
    String? chat,
    String? sender,
  }) async {
    final h = await c.postMsg(
      chatId: chat ?? chatId,
      text: jsonCard(payload),
      jwt: jwt ?? c.buyerJwt,
      sender: sender,
    );
    final persisted = h.ok && h.firstId != null;
    if (persisted && h.firstId != null) c.createdMsgIds.add(h.firstId!);
    if (persisted) {
      final row = await c.orderRow(payload['order_id']?.toString() ?? oid);
      if (countIfPersist) {
        c.hold(
          id: id,
          lens: lens,
          severity: severity,
          title: title ?? 'card persistiu ${payload['kind']}',
          actor: 'buyer JWT',
          pre: 'denylist BXCC sem este rail/encoding/URL',
          repro: 'POST chat_messages FLEABER_JSON_V1:${jsonEncode(payload)}',
          expected: 'chat_system_card_notes_forbidden / url_denied / label_mismatch',
          obtained: h.brief,
          evidence: {
            'id': h.firstId,
            'kind': payload['kind'],
            'payload': payload,
            'order_status': row?['status'],
          },
        );
      } else {
        c.note(id, 'persistiu (controlo exacto, não contar)', h.brief, lens: lens);
      }
    } else {
      c.block(id, lens, 'recusado', h.brief);
    }
    return persisted ? h.map : null;
  }

  Future<void> tryInbox(String id, String text,
      {bool count = true, String severity = 'P1'}) async {
    final h = await c.rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: c.buyerJwt,
      body: {'last_message': text},
    );
    final row = await c.chatRow(chatId);
    final stored = '${row?['last_message']}';
    if (h.ok && stored == text) {
      if (count) {
        c.hold(
          id: id,
          lens: 'CE5',
          severity: severity,
          title: 'inbox last_message forjado: $text',
          actor: 'buyer JWT',
          pre: 'chats_update_participants + forged_inbox_preview BXCC',
          repro: 'PATCH chats.last_message=$text',
          expected: 'chat_inbox_preview_forbidden',
          obtained: stored,
        );
      } else {
        c.note(id, 'inbox persistiu (controlo, não contar)', stored, lens: 'CE5');
      }
    } else {
      c.block(id, 'CE5', 'inbox recusado', {'http': h.brief, 'stored': stored});
    }
  }

  // ---- CE-A matriz rails NOVOS (não Skrill/Neteller/Paysafe/MoneyGram/GCash/PM/enviado MB) ----
  const newRails = <String, String>{
    'wechat': 'WeChat Pay 12,00 €',
    'wechat-zh': '微信支付 12,00 €',
    'alipay-zh': '支付宝 12,00 €',
    'upi': 'UPI 12,00 €',
    'cashtag': r'$cashtag 12,00 €',
    'cashapp-oneword': 'CashApp Pay 12,00 €',
    'venmo-biz': 'Venmo Business 12,00 €',
    'revolut-me': 'Revolut Me 12,00 €',
    'wise-link': 'Wise link 12,00 €',
    'interac-e': 'Interac e-Transfer 12,00 €',
    'usdt-trc20': 'USDT TRC20 12,00 €',
    'btc-wallet': 'BTC wallet 12,00 €',
    'wallet-send': 'envia para esta wallet 12,00 €',
    'ja-transferi-mb': 'já transferi MB 12,00 €',
    'comprovativo-mb': 'comprovativo multibanco',
    'enviei-mbway': 'enviei por MBWay',
    'pago-transf': 'pago por transferência',
    'pago-transf-amt': 'pago por transferência 12,00 €',
    'unionpay': 'UnionPay 12,00 €',
    'mpesa': 'M-Pesa 12,00 €',
    'swish': 'Swish 12,00 €',
    'kakaopay': 'KakaoPay 12,00 €',
    'linepay': 'LINE Pay 12,00 €',
    'grabpay': 'GrabPay 12,00 €',
    'blik': 'Blik 12,00 €',
    'vipps': 'Vipps 12,00 €',
    'paynow': 'PayNow 12,00 €',
    'payid': 'PayID 12,00 €',
    'osko': 'Osko 12,00 €',
    'dana': 'Dana 12,00 €',
    'momo': 'MoMo 12,00 €',
    'tng': 'Touch n Go 12,00 €',
    'mb-hyphen': 'MB-WAY 12,00 €',
    'pay-pal-space': 'Pay Pal 12,00 €',
    'paypal-i': 'PayPaI 12,00 €',
  };

  for (final e in newRails.entries) {
    await tryCard(
      id: 'CEA.notes-${e.key}',
      lens: 'CE1',
      title: 'card reservation_payment_submitted notes=${e.value}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': e.value,
      },
    );
  }

  // controlos exactos BXCC — NÃO contar
  for (final e in {
    'skrill': 'Skrill 12,00 €',
    'enviado-mb': 'enviado MB',
    'payoneer': 'Payoneer 12,00 €',
  }.entries) {
    await tryCard(
      id: 'CEA.ctrl-${e.key}',
      lens: 'CE1',
      countIfPersist: false,
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': e.value,
      },
    );
  }

  // seguro_fleaber_paid com rails novos
  for (final key in ['wechat', 'upi', 'cashtag', 'unionpay', 'ja-transferi-mb', 'mb-hyphen']) {
    await tryCard(
      id: 'CEA.seguro-$key',
      lens: 'CE1',
      chat: paid.chatId,
      title: 'seguro_fleaber_paid label=${newRails[key]}',
      payload: {
        'kind': 'seguro_fleaber_paid',
        'order_id': paid.oid,
        'total': paidTotal,
        'label': newRails[key],
      },
    );
  }

  // ---- Homógrafos Cyrillic/Greek em PayPal / MB WAY / Clearpay ----
  const cyrM = '\u041C'; // М looks like M
  const cyrVe = '\u0412'; // В looks like B
  const cyrEs = '\u0421'; // С looks like C
  const shy = '\u00AD';
  const hangulFiller = '\u3164';
  const invPlus = '\u2064';
  const braille = '\u2800';
  const enQuad = '\u2000';
  const ideoSpace = '\u3000';
  const khmer = '\u17B4';

  final homoglyphs = <String, String>{
    'mbway-cyr-m': '${cyrM}B WAY 12,00 €',
    'mbway-cyr-b': 'M${cyrVe} WAY 12,00 €',
    'clearpay-cyr-c': '${cyrEs}learpay 12,00 €',
    'paypal-math': '𝖯𝖺𝗒𝖯𝖺𝗅 12,00 €',
  };
  for (final e in homoglyphs.entries) {
    await tryCard(
      id: 'CEA.homo-${e.key}',
      lens: 'CE1',
      title: 'homógrafo notes=${e.value}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': e.value,
      },
    );
  }

  // ---- Zero-width / fillers em rails AINDA NÃO exactos BXCC (WeChat/UPI) ----
  final encodedNew = <String, String>{
    'wechat-hangul': 'WeChat${hangulFiller}Pay 12,00 €',
    'wechat-invplus': 'WeChat${invPlus}Pay 12,00 €',
    'wechat-braille': 'WeChat${braille}Pay 12,00 €',
    'upi-enquad': 'UPI${enQuad}12,00 €',
    'upi-ideo': 'UPI${ideoSpace}12,00 €',
    'wechat-khmer': 'WeChat${khmer}Pay 12,00 €',
    'wechat-shy': 'We${shy}Chat Pay 12,00 €',
  };
  for (final e in encodedNew.entries) {
    await tryCard(
      id: 'CEA.enc-${e.key}',
      lens: 'CE2',
      title: 'encoding em rail novo notes codeUnits=${e.value.codeUnits}',
      payload: {
        'kind': 'reservation_payment_submitted',
        'order_id': oid,
        'notes': e.value,
      },
    );
  }

  // inbox com rails novos
  await tryInbox('CEA.inbox-wechat', 'WeChat Pay 12,00 €');
  await tryInbox('CEA.inbox-upi', 'UPI 12,00 €');
  await tryInbox('CEA.inbox-cashtag', r'$cashtag pago');
  await tryInbox('CEA.inbox-ja-mb', 'já transferi MB 12,00 €');
  await tryInbox('CEA.inbox-mb-hyphen', 'MB-WAY 12,00 €');
  await tryInbox('CEA.inbox-homo-clear', '${cyrEs}learpay 12,00 €');
  await tryInbox('CEA.ctrl-skrill', 'Skrill 12,00 €', count: false);

  await dumpJson('${outDir()}/pass1.json', {
    'pass': 1,
    'poco': 'CE-A',
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln('PASS1 findings=${c.findings.length} blocked=${c.blocked.length}');
}
