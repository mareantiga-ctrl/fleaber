/// Confirmações pontuais CG (sem corrigir).
import 'dart:convert';
import 'dart:io';
import '_rtcg.dart';

Future<void> main() async {
  final c = Rtcg.fromEnv(loadEnv());
  await c.loginActors();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s2 = ids['s2'] as String;
  final prodUnpub = ids['prodUnpub'] as String?;

  final rtcf = '6c9febff-91da-475e-9629-c6cb1720661f';
  final p = await c.profile(rtcf);
  stdout.writeln('RTCF seller hub_published=${p?['hub_published']} handle=${p?['handle']}');

  final mkt = await c.rest(
    'GET',
    'products?list_on_marketplace=eq.true&select=id,seller_id,title,price,quantity&order=created_at.desc&limit=30',
    jwt: c.buyerJwt,
  );
  stdout.writeln('mkt desc n=${mkt.list.length} ${mkt.brief}');
  final has = mkt.list.any((r) => r is Map && '${r['id']}' == prodUnpub);
  stdout.writeln('mkt has unpub sku=$has prod=$prodUnpub');

  final bySeller = await c.rest(
    'GET',
    'products?seller_id=eq.$s2&select=id,title,price,quantity,list_on_marketplace',
    jwt: c.buyerJwt,
  );
  stdout.writeln('by seller ${bySeller.brief}');

  final feed = await c.rest(
    'GET',
    'lives?status=eq.live&is_active=eq.true&select=id,seller_id,title&limit=80',
    jwt: c.buyerJwt,
  );
  stdout.writeln('feed n=${feed.list.length}');
  for (final row in feed.list) {
    if (row is Map) {
      final sid = '${row['seller_id']}';
      final pr = await c.profile(sid);
      if (pr?['hub_published'] != true) {
        stdout.writeln('UNPUB IN FEED ${row['id']} ${row['title']} hub=${pr?['hub_published']}');
      }
    }
  }
}
