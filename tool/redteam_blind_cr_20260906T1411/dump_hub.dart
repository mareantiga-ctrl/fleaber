/// Dump Hub system msgs for FOMO live. No fixes.
import 'dart:io';

import '_rtcr.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  final liveId = Platform.environment['LIVE'] ??
      (throw StateError('set LIVE'));
  final hub = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveId'
        '&kind=eq.system&select=id,kind,body,sender_label,created_at'
        '&order=created_at.asc&limit=80',
    jwt: c.buyerJwt,
  );
  final anon = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveId'
        '&kind=eq.system&select=id,kind,body,sender_label,created_at'
        '&order=created_at.asc&limit=80',
  );
  await dumpJson('${outDir()}/confirm_hub_msgs.json', {
    'liveId': liveId,
    'buyer_n': hub.list.length,
    'anon_n': anon.list.length,
    'buyer': hub.list,
    'anon': anon.list,
    'buyer_http': hub.brief,
    'anon_http': anon.brief,
  });
  stdout.writeln('buyer n=${hub.list.length}');
  stdout.writeln('anon n=${anon.list.length}');
  for (final m in hub.list) {
    if (m is Map) {
      stdout.writeln('${m['sender_label']} | ${m['kind']} | ${m['body']}');
    }
  }
}
