/// Pass 2 — J3 storage buckets cross-user. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtj.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtj.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  final bucketsGet = await c.req('GET', '/storage/v1/bucket', jwt: c.buyer2Jwt);
  c.note('buckets.jwt', {
    'http': bucketsGet.status,
    'body': clip(bucketsGet.body, 800),
  });
  final bucketsSvc = await c.req('GET', '/storage/v1/bucket', service: true);
  c.note('buckets.svc', {
    'http': bucketsSvc.status,
    'n': bucketsSvc.list.length,
    'ids': bucketsSvc.list
        .whereType<Map>()
        .map((e) => {
              'id': e['id'],
              'public': e['public'],
              'name': e['name'],
            })
        .toList(),
  });

  final bucketIds = bucketsSvc.list
      .whereType<Map>()
      .map((e) => e['id']?.toString() ?? e['name']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();

  Future<Map<String, Object?>> listPrefix(
    String bucket,
    String prefixPath, {
    String? jwt,
    bool service = false,
  }) async {
    final h = await c.req(
      'POST',
      '/storage/v1/object/list/$bucket',
      jwt: jwt,
      service: service,
      body: {
        'prefix': prefixPath,
        'limit': 20,
        'offset': 0,
      },
    );
    return {
      'bucket': bucket,
      'prefix': prefixPath,
      'http': h.status,
      'n': h.list.length,
      'names': h.list
          .whereType<Map>()
          .map((e) => e['name'])
          .take(8)
          .toList(),
      'body': clip(h.body, 240),
    };
  }

  final lists = <Map<String, Object?>>[];
  for (final b in bucketIds) {
    lists.add(await listPrefix(b, '', jwt: c.buyer2Jwt));
    lists.add(await listPrefix(b, '', jwt: c.buyerJwt));
  }

  // Known prefixes
  for (final b in [
    'chat-media',
    'chat_media',
    'fleaber-private',
    'fleaber_private',
    'product_media',
    'avatars',
  ]) {
    if (!bucketIds.contains(b)) continue;
    lists.add(await listPrefix(b, 'chat_uploads/', jwt: c.buyer2Jwt));
    lists.add(await listPrefix(b, 'order_proofs/', jwt: c.buyer2Jwt));
    lists.add(await listPrefix(b, 'order_disputes/', jwt: c.buyer2Jwt));
    lists.add(await listPrefix(
        b, 'order_proofs/${c.buyerId}/', jwt: c.buyer2Jwt));
    lists.add(await listPrefix(
        b, 'chat_uploads/${c.buyerId}/', jwt: c.buyer2Jwt));
    lists.add(await listPrefix(
        b, 'order_proofs/${c.sellerId}/', jwt: c.buyerJwt));
  }

  // Seller lists buyer proofs (counterparty over-read: ANY order with this buyer)
  for (final b in ['fleaber_private', 'fleaber-private', 'chat_media', 'chat-media']) {
    if (!bucketIds.contains(b)) continue;
    lists.add(await listPrefix(
        b, 'order_proofs/${c.buyerId}/', jwt: c.sellerJwt));
    lists.add(await listPrefix(
        b, 'chat_uploads/${c.buyerId}/', jwt: c.sellerJwt));
    lists.add(await listPrefix(
        b, 'order_disputes/${c.buyerId}/', jwt: c.sellerJwt));
  }

  c.note('lists', lists);

  for (final l in lists) {
    final n = l['n'] as int? ?? 0;
    final http = l['http'];
    final bucket = l['bucket']?.toString() ?? '';
    final pref = l['prefix']?.toString() ?? '';
    final isRoot = pref.isEmpty;
    if (http == 200 && n > 0 && isRoot) {
      c.addFinding(finding(
        id: '$prefix-J3-LIST-ROOT-$bucket',
        lens: 'J3',
        severity: 'P1',
        title: 'JWT lista raiz do bucket $bucket',
        pre: 'POST object/list prefix=',
        repro: 'POST /storage/v1/object/list/$bucket',
        proven: true,
        evidence: l,
      ));
    }
    if (http == 200 &&
        n > 0 &&
        pref.contains('${c.buyerId}') &&
        bucket.contains('private')) {
      // seller listing buyer proofs may be counterparty-OK; buyer2 is not
      // distinguished in this loop — check notes later.
    }
  }

  // Upload as buyer2 into own prefix + into victim prefix
  final tiny = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
  // storage upload is binary — use a small JSON placeholder via REST? Storage API wants octet-stream.
  Future<Map<String, Object?>> upload(
    String bucket,
    String objectPath, {
    required String jwt,
  }) async {
    final h = await c.req(
      'POST',
      '/storage/v1/object/$bucket/$objectPath',
      jwt: jwt,
      extra: {
        'Content-Type': 'image/png',
        'x-upsert': 'true',
      },
      body: jsonEncode({
        // body helper json-encodes; send a tiny marker string instead of png
        'rtj': prefix,
      }),
    );
    return {
      'bucket': bucket,
      'path': objectPath,
      'http': h.status,
      'body': h.snippet,
    };
  }

  final uploads = <Map<String, Object?>>[];
  for (final b in bucketIds) {
    uploads.add(await upload(
      b,
      'chat_uploads/${c.sellerId}/$prefix-cross.json',
      jwt: c.buyer2Jwt!,
    ));
    uploads.add(await upload(
      b,
      'order_proofs/${c.sellerId}/$prefix-cross.json',
      jwt: c.buyer2Jwt!,
    ));
    uploads.add(await upload(
      b,
      'chat_uploads/${c.buyer2Id}/$prefix-own.json',
      jwt: c.buyer2Jwt!,
    ));
    uploads.add(await upload(
      b,
      'product_photos/${c.sellerId}/$prefix-cross.json',
      jwt: c.buyer2Jwt!,
    ));
  }
  c.note('uploads', uploads);

  for (final u in uploads) {
    if (u['http'] == 200 || u['http'] == 201) {
      final path = u['path']?.toString() ?? '';
      final own = path.contains('${c.buyer2Id}');
      if (!own) {
        c.addFinding(finding(
          id: '$prefix-J3-UPLOAD-CROSS',
          lens: 'J3',
          severity: 'P1',
          title: 'Upload para prefixo alheio (${u['bucket']})',
          pre: 'JWT buyer2, path com UUID seller',
          repro: 'POST /storage/v1/object/${u['bucket']}/${u['path']}',
          proven: true,
          evidence: u,
        ));
      }
    }
  }

  // Download attempts: find any object via svc in private buckets and GET as buyer2
  final downloads = <Map<String, Object?>>[];
  for (final b in ['fleaber_private', 'fleaber-private', 'chat_media', 'chat-media']) {
    if (!bucketIds.contains(b)) continue;
    final svcList = await listPrefix(b, '', service: true);
    c.note('svc.list.$b', svcList);
    final names = (svcList['names'] as List?) ?? [];
    for (final name in names.take(5)) {
      final n = name.toString();
      if (n.isEmpty) continue;
      final get = await c.req(
        'GET',
        '/storage/v1/object/$b/$n',
        jwt: c.buyer2Jwt,
      );
      downloads.add({
        'bucket': b,
        'name': n,
        'http': get.status,
        'len': get.body.length,
        'snip': clip(get.body, 80),
      });
      if (get.ok && get.body.length > 10) {
        final own = n.contains('${c.buyer2Id}');
        if (!own) {
          c.addFinding(finding(
            id: '$prefix-J3-GET-CROSS',
            lens: 'J3',
            severity: 'P1',
            title: 'GET objecto alheio em $b',
            pre: 'JWT buyer2',
            repro: 'GET /storage/v1/object/$b/$n',
            proven: true,
            evidence: {'name': n, 'http': get.status, 'len': get.body.length},
          ));
        }
      }
    }
  }
  c.note('downloads', downloads);

  // signed URL for victim object
  if (downloads.isNotEmpty) {
    final victim = downloads.first;
    final sign = await c.req(
      'POST',
      '/storage/v1/object/sign/${victim['bucket']}/${victim['name']}',
      jwt: c.buyer2Jwt,
      body: {'expiresIn': 60},
    );
    c.note('signed', {'http': sign.status, 'body': sign.snippet});
    if (sign.ok && (sign.map?['signedURL'] != null || sign.body.contains('token='))) {
      c.addFinding(finding(
        id: '$prefix-J3-SIGNED-CROSS',
        lens: 'J3',
        severity: 'P1',
        title: 'buyer2 emitiu signed URL de objecto alheio',
        pre: 'POST object/sign',
        repro: 'POST /storage/v1/object/sign/...',
        proven: true,
        evidence: {'http': sign.status, 'body': sign.snippet},
      ));
    }
  }

  await dumpJson(
    '${Directory.current.path}/out/pass2.json',
    {'prefix': prefix, 'notes': c.notes, 'findings': c.findings},
  );
  stdout.writeln('pass2 findings=${c.findings.length}');
  for (final f in c.findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} ${f['title']}');
  }
}
