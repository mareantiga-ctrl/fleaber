/// RED TEAM CEGO CG pass3 — storage Hub + composição discovery→tip/Mux.
import 'dart:convert';
import 'dart:io';
import '_rtcg.dart';

Future<void> main() async {
  final c = Rtcg.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;
  final b1 = ids['b1'] as String;
  final airUnpub = ids['airUnpub'] as String;
  final prodUnpub = ids['prodUnpub'] as String?;
  final itemUnpub = ids['itemUnpub'] as String?;

  final buckets = ['fleaber_private', 'chat_media', 'avatars', 'product_photos'];
  final bucketsAnon = await c.req('GET', '/storage/v1/bucket');
  final bucketsB1 = await c.req('GET', '/storage/v1/bucket', jwt: c.buyerJwt);
  c.note('cg6.buckets.anon', 'list buckets anon', bucketsAnon, lens: 'CG6');
  c.note('cg6.buckets.b1', 'list buckets B1', bucketsB1, lens: 'CG6');
  if (bucketsAnon.ok && bucketsAnon.list.isNotEmpty) {
    c.hold(
      id: 'CG6-BUCKETS-ANON',
      lens: 'CG6',
      severity: 'P3',
      title: 'anon lista buckets storage',
      actor: 'anon',
      pre: 'GET /storage/v1/bucket',
      repro: 'GET /storage/v1/bucket',
      expected: '401 / []',
      obtained: bucketsAnon.brief,
    );
  } else {
    c.block('cg6.buckets.anon', 'CG6', 'anon não lista buckets', bucketsAnon);
  }

  for (final b in buckets) {
    final listAnon = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      body: {'prefix': '', 'limit': 20},
    );
    final listB1 = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      jwt: c.buyerJwt,
      body: {'prefix': '', 'limit': 20},
    );
    final listAlien = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      jwt: c.buyer2Jwt,
      body: {'prefix': '$s1/', 'limit': 20},
    );
    final trav = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      jwt: c.buyerJwt,
      body: {
        'prefix': 'product_photos/$b1/../$s1/',
        'limit': 20,
      },
    );
    final travEnc = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      jwt: c.buyerJwt,
      body: {
        'prefix': 'product_photos/$b1/%2e%2e/$s1/',
        'limit': 20,
      },
    );
    c.note('cg6.list.anon.$b', 'list $b anon', listAnon, lens: 'CG6');
    c.note('cg6.list.b1.$b', 'list $b B1', listB1, lens: 'CG6');
    c.note('cg6.list.alien.$b', 'list prefix S1 as B2', listAlien, lens: 'CG6');
    c.note('cg6.trav.$b', 'list traversal', trav, lens: 'CG6');
    c.note('cg6.travenc.$b', 'list %2e%2e', travEnc, lens: 'CG6');

    if (b == 'fleaber_private' && listAnon.ok && listAnon.list.isNotEmpty) {
      c.hold(
        id: 'CG6-LIST-PRIVATE-ANON',
        lens: 'CG6',
        severity: 'P1',
        title: 'anon lista fleaber_private',
        actor: 'anon',
        pre: b,
        repro: 'POST /storage/v1/object/list/fleaber_private',
        expected: '400/401/[]',
        obtained: listAnon.brief,
      );
    }

    final names = <String>[];
    for (final row in [...listB1.list, ...listAlien.list, ...trav.list]) {
      if (row is Map && row['name'] != null) names.add('${row['name']}');
    }
    final alienName = names.any((n) => n.contains(s1) || n.contains(s2));
    if (alienName && listAlien.list.isNotEmpty) {
      c.hold(
        id: 'CG6-LIST-ALIEN-$b',
        lens: 'CG6',
        severity: 'P1',
        title: 'B2 lista prefixo storage de S1 em $b',
        actor: 'B2',
        pre: 'prefix=$s1/',
        repro: 'POST object/list/$b prefix=S1/',
        expected: '[]',
        obtained: listAlien.brief,
      );
    }

    final pubGet = await c.req(
      'GET',
      '/storage/v1/object/public/$b/rtcg-does-not-exist.png',
    );
    c.note('cg6.public.$b', 'GET public $b missing', pubGet, lens: 'CG6');
  }

  // Upload + GET cruzado
  final ownPath = 'product_photos/$b1/rtcg1235.txt';
  final up = await c.req(
    'POST',
    '/storage/v1/object/chat_media/$ownPath',
    jwt: c.buyerJwt,
    body: {'ping': true},
    extra: {'Content-Type': 'application/json', 'x-upsert': 'true'},
  );
  c.note('cg6.upload.b1', 'upload chat_media own', up, lens: 'CG6');
  final getB2 = await c.req(
    'GET',
    '/storage/v1/object/authenticated/chat_media/$ownPath',
    jwt: c.buyer2Jwt,
  );
  final getPub = await c.req(
    'GET',
    '/storage/v1/object/public/chat_media/$ownPath',
  );
  final getTrav = await c.req(
    'GET',
    '/storage/v1/object/authenticated/chat_media/product_photos/$b1/../$s1/secret.txt',
    jwt: c.buyerJwt,
  );
  c.note('cg6.get.b2', 'B2 GET ficheiro B1', getB2, lens: 'CG6');
  c.note('cg6.get.pub', 'anon GET public chat_media', getPub, lens: 'CG6');
  c.note('cg6.get.trav', 'GET traversal', getTrav, lens: 'CG6');
  if (getB2.ok && getB2.status == 200 && getB2.body.contains('ping')) {
    c.hold(
      id: 'CG6-GET-ALIEN',
      lens: 'CG6',
      severity: 'P1',
      title: 'B2 lê objecto chat_media de B1',
      actor: 'B2',
      pre: ownPath,
      repro: 'GET object/authenticated/chat_media/$ownPath',
      expected: '400/403',
      obtained: getB2.brief,
    );
  } else {
    c.block('cg6.get.b2', 'CG6', 'GET cruzado recusado', getB2);
  }

  // avatars / photo_url of unpublished
  final s2p = await c.profile(s2);
  final photo = '${s2p?['photo_url'] ?? ''}';
  c.note('cg6.photo.s2', 'S2 photo_url', photo, lens: 'CG6');
  if (photo.startsWith('http')) {
    final img = await c.rawGet(photo);
    c.note('cg6.photo.fetch', 'GET photo unpublished', img.status, lens: 'CG6');
  }

  // ---------- CG7 composição: UUID unpublished → products → tip/mux ----------
  final feedB1 = await c.rest(
    'GET',
    'lives?status=eq.live&is_active=eq.true&select=id,seller_id,title,status&limit=50',
    jwt: c.buyerJwt,
  );
  c.note('cg7.feed.b1', 'B1 feed all live+active', feedB1, lens: 'CG7');
  final feedHasUnpub = feedB1.list.any((row) {
    if (row is! Map) return false;
    return '${row['id']}' == airUnpub || '${row['seller_id']}' == s2;
  });
  if (feedHasUnpub) {
    c.hold(
      id: 'CG7-FEED-UNPUB-AIR',
      lens: 'CG7',
      severity: 'P2',
      title: 'feed REST live+active inclui loja unpublished (sem UUID prévio)',
      actor: 'B1',
      pre: 'S2 hub off broadcasting',
      repro: 'GET lives?status=eq.live&is_active=eq.true',
      expected: 'só lojas hub_published (alinhado a discovery)',
      obtained: feedB1.brief,
    );
  } else {
    c.block('cg7.feed', 'CG7', 'feed não inclui unpublished air', feedB1);
  }

  final mktB1 = await c.rest(
    'GET',
    'products?list_on_marketplace=eq.true&select=id,seller_id,title,price,quantity&limit=80',
    jwt: c.buyerJwt,
  );
  c.note('cg7.mkt.b1', 'B1 marketplace products enum', mktB1, lens: 'CG7');
  final mktHasUnpub = mktB1.list.any((row) {
    if (row is! Map) return false;
    return '${row['seller_id']}' == s2 || '${row['id']}' == (prodUnpub ?? '');
  });
  if (mktHasUnpub) {
    c.hold(
      id: 'CG7-MKT-ENUM-UNPUB',
      lens: 'CG7',
      severity: 'P2',
      title: 'enum marketplace JWT inclui SKU de loja unpublished',
      actor: 'B1',
      pre: 'sem UUID prévio; GET products list_on_marketplace',
      repro: 'GET products?list_on_marketplace=eq.true',
      expected: 'só vitrine Hub / hub_products_public',
      obtained: mktB1.brief,
    );
  } else {
    c.block('cg7.mkt', 'CG7', 'enum mkt sem SKU unpublished', mktB1);
  }

  final profB1 = await c.rest(
    'GET',
    'profiles?handle=eq.rtcg1235s2&select=id,handle,hub_published',
    jwt: c.buyerJwt,
  );
  final uuid = col(profB1.map, 'id') ?? s2;
  final lives = await c.rest(
    'GET',
    'lives?seller_id=eq.$uuid&select=id,status,is_active,title',
    jwt: c.buyerJwt,
  );
  final products = await c.rest(
    'GET',
    'products?seller_id=eq.$uuid&select=id,title,price,quantity',
    jwt: c.buyerJwt,
  );
  c.note('cg7.chain.profile', 'handle→UUID unpublished', profB1, lens: 'CG7');
  c.note('cg7.chain.lives', 'UUID→lives', lives, lens: 'CG7');
  c.note('cg7.chain.products', 'UUID→products', products, lens: 'CG7');

  String? liveId;
  if (leakRow(lives)) liveId = col(lives.map, 'id');
  liveId ??= airUnpub;

  final rm = await c.edge(
    'resolve-mux-playback',
    jwt: c.buyerJwt,
    body: {'live_id': liveId},
  );
  final tip = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': liveId,
      'seller_id': uuid,
      'amount_eur': 1,
    },
  );
  c.note('cg7.chain.mux', 'UUID live → resolve-mux', rm, lens: 'CG7');
  c.note('cg7.chain.tip', 'UUID live → tip checkout', tip, lens: 'CG7');

  final chainMux = rm.ok && col(rm.map, 'playback_id') != null;
  final chainTip = tip.ok;
  final chainStock = leakRow(products);
  if ((chainMux || chainTip) && chainStock) {
    c.hold(
      id: 'CG7-COMPOSE-UNPUB-MONEY',
      lens: 'CG7',
      severity: chainTip ? 'P1' : 'P2',
      title: 'composição: profiles unpublished → stock + tip/Mux',
      actor: 'B1/B2',
      pre: 'handle rtcg1235s2 hub off',
      repro:
          'GET profiles handle → GET products/lives → POST tip ou resolve-mux',
      expected: 'cadeia parte na 1.ª superfície pública',
      obtained: {
        'profile': profB1.brief,
        'lives': lives.brief,
        'products': products.brief,
        'mux': rm.brief,
        'tip': tip.brief,
      },
    );
  } else if (chainStock && leakRow(lives)) {
    c.hold(
      id: 'CG7-COMPOSE-UNPUB-STOCK',
      lens: 'CG7',
      severity: 'P2',
      title: 'composição: handle unpublished → lives+products REST',
      actor: 'B1',
      pre: 'Hub views []',
      repro: 'profiles.handle → lives + products',
      expected: 'sem stock/live de loja desligada',
      obtained: {
        'profile': profB1.brief,
        'lives': lives.brief,
        'products': products.brief,
        'mux': rm.brief,
        'tip': tip.brief,
      },
    );
  } else {
    c.block('cg7.compose', 'CG7', 'cadeia unpublished não chega a stock/tip', {
      'mux': rm.brief,
      'tip': tip.brief,
      'stock': products.brief,
    });
  }

  if (itemUnpub != null) {
    final fomo = await c.rpc(
      'batata_hub_live_fomo_snapshot',
      {'p_live_id': airUnpub},
      jwt: c.buyerJwt,
    );
    c.note('cg7.fomo', 'FOMO após cadeia', fomo, lens: 'CG7');
  }
  if (prodUnpub != null) {
    c.note('cg7.prodUnpub', 'prod id', prodUnpub, lens: 'CG7');
  }

  await dumpJson('${outDir()}/pass3.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
  });
}
