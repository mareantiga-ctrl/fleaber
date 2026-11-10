/// RED TEAM CEGO BU pass2 — descida storage fleaber_private. Sem correcções.
import 'dart:io';
import '_rtbu.dart';

Future<void> main() async {
  final c = Rtbu.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  Future<HttpHit> list(String bucket, String prefix, {String? jwt, bool anon = false}) {
    return c.req(
      'POST',
      '/storage/v1/object/list/$bucket',
      jwt: anon ? null : (jwt ?? c.buyerJwt),
      body: {'prefix': prefix, 'limit': 20},
    );
  }

  for (final prefix in [
    '',
    'order_disputes/',
    'order_proofs/',
    'chat_uploads/',
    'order_disputes/${c.buyerId}/',
    'order_disputes/${c.sellerId}/',
    'order_proofs/${c.buyerId}/',
    'order_proofs/${c.sellerId}/',
    'chat_uploads/${c.sellerId}/',
  ]) {
    final b1 = await list('fleaber_private', prefix);
    c.note('p2.list.b1', 'B1 prefix="$prefix"', b1, lens: 'BU6');
    final b2 = await list('fleaber_private', prefix, jwt: c.buyer2Jwt);
    c.note('p2.list.b2', 'B2 prefix="$prefix"', b2, lens: 'BU6');
    final an = await list('fleaber_private', prefix, anon: true);
    c.note('p2.list.anon', 'anon prefix="$prefix"', an, lens: 'BU6');

    final names = b1.list
        .whereType<Map>()
        .map((e) => '${e['name'] ?? ''}')
        .where((n) => n.isNotEmpty)
        .toList();
    final foreign = names.where((n) {
      final id = c.buyerId ?? '';
      return id.isNotEmpty && n.contains('-') && !n.contains(id);
    }).toList();

    if (prefix.startsWith('order_') && names.isNotEmpty) {
      final otherUid = prefix.contains(c.sellerId ?? 'nope') ||
          names.any((n) => (c.sellerId != null && n.contains(c.sellerId!)) ||
              (c.buyer2Id != null && n.contains(c.buyer2Id!)));
      if (otherUid || foreign.isNotEmpty) {
        c.hold(
          id: 'BU6-PRIVATE-CROSS-LIST',
          lens: 'BU6',
          severity: 'P1',
          title: 'B1 lista paths fleaber_private de outro uid',
          actor: 'B1',
          pre: 'prefix=$prefix',
          repro: 'POST /storage/v1/object/list/fleaber_private prefix=$prefix',
          expected: 'só objectos do próprio uid',
          obtained: names.take(12).toList(),
        );
      }
    }

    for (final n in names.take(3)) {
      if (n.endsWith('/') || n == 'order_disputes' || n == 'order_proofs' || n == 'chat_uploads') {
        continue;
      }
      final path = prefix.endsWith('/') || prefix.isEmpty ? '$prefix$n' : n;
      final g = await c.req(
        'GET',
        '/storage/v1/object/authenticated/fleaber_private/$path',
        jwt: c.buyerJwt,
      );
      c.note('p2.get.auth', 'GET auth $path', '${g.status} ${g.body.length}b', lens: 'BU6');
      if (g.status == 200 && g.body.length > 40) {
        final other = c.sellerId != null && path.contains(c.sellerId!);
        c.hold(
          id: other ? 'BU6-PRIVATE-CROSS-READ' : 'BU6-PRIVATE-READ',
          lens: 'BU6',
          severity: other ? 'P1' : 'P2',
          title: other
              ? 'B1 lê ficheiro fleaber_private de outro uid'
              : 'B1 lê ficheiro fleaber_private (próprio ou ambíguo)',
          actor: 'B1',
          pre: path,
          repro: 'GET /storage/v1/object/authenticated/fleaber_private/$path',
          expected: '403 excepto dono',
          obtained: 'HTTP ${g.status} bytes=${g.body.length}',
        );
      }
    }
  }

  // chat_media descent
  for (final prefix in ['', 'product_photos/', 'order_proofs/', 'order_disputes/']) {
    final h = await list('chat_media', prefix);
    c.note('p2.chat.list', 'chat_media "$prefix"', h, lens: 'BU6');
    final names = h.list
        .whereType<Map>()
        .map((e) => '${e['name'] ?? ''}')
        .where((n) => n.isNotEmpty)
        .toList();
    if (prefix.contains('order_') && names.isNotEmpty) {
      c.hold(
        id: 'BU6-CHAT-PROOF-LIST',
        lens: 'BU6',
        severity: 'P1',
        title: 'chat_media lista order_proofs/disputes',
        actor: 'B1',
        pre: prefix,
        repro: 'POST list chat_media prefix=$prefix',
        expected: '[]',
        obtained: names.take(10).toList(),
      );
    }
    for (final n in names.take(2)) {
      if (n.contains('.')) {
        final path = prefix + n;
        final g = await c.req('GET', '/storage/v1/object/public/chat_media/$path');
        c.note('p2.chat.get', 'public $path', '${g.status} ${g.body.length}b', lens: 'BU6');
      }
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  });
  stdout.writeln('PASS2 findings=${c.findings.length}');
}
