/// Dump hub-visible FOMO bodies for the frozen report.
import 'dart:io';

import '_rtcl.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  const liveId = '3b8096de-c154-4533-ad17-6b07f5100390';
  final hub = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveId&select=id,kind,body,sender_label&order=created_at.asc&limit=80',
    jwt: c.buyerJwt,
  );
  await dumpJson('${outDir()}/confirm_hub_msgs.json', {
    'liveId': liveId,
    'http': hub.status,
    'n': hub.list.length,
    'rows': hub.list,
  });
  stdout.writeln('hub n=${hub.list.length}');
  for (final row in hub.list) {
    if (row is Map) {
      stdout.writeln('${row['kind']} | ${row['sender_label']} | ${row['body']}');
    }
  }
}
