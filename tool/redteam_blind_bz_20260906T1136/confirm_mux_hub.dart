/// Confirm Hub vs REST mux_playback_id on unpublished + scheduled. No fixes.
import 'dart:io';

import '_rtbz.dart';

Future<void> main() async {
  final c = Rtbz.fromEnv(loadEnv());
  await c.loginActors();

  final lives = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,title,status,is_active,seller_id&limit=80',
    service: true,
  );
  stdout.writeln('lives ${lives.list.length}');

  for (final row in lives.list.whereType<Map>()) {
    final id = row['id']?.toString();
    final title = row['title']?.toString() ?? '';
    if (id == null) continue;
    if (!title.contains('mux')) continue;

    final restB = await c.rest(
      'GET',
      'lives?id=eq.$id&select=id,status,mux_playback_id',
      jwt: c.buyerJwt,
    );
    final hub = await c.rest(
      'GET',
      'hub_lives_public?id=eq.$id&select=id,status,mux_playback_id',
      jwt: c.buyerJwt,
    );
    final disc = await c.rest(
      'GET',
      'hub_lives_discovery_public?id=eq.$id&select=id,status,mux_playback_id',
      jwt: c.buyerJwt,
    );
    stdout.writeln('--- $title status=${row['status']} active=${row['is_active']}');
    stdout.writeln('REST buyer ${restB.brief}');
    stdout.writeln('HUB ${hub.brief}');
    stdout.writeln('DISC ${disc.brief}');
  }
}
