/// Dump hub-visible FOMO bodies for the frozen report.
import 'dart:io';

import '_rtcr.dart';

Future<void> main() async {
  final c = Rtcr.fromEnv(loadEnv());
  await c.loginActors();
  const liveId = '5e34342f-7ae6-4f43-a1e3-b9a6a5c8fe48';
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
