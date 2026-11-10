/// Dump hub-visible FOMO bodies for the frozen report.
import 'dart:convert';
import 'dart:io';

import '_rtdd.dart';

Future<void> main() async {
  final c = Rtdd.fromEnv(loadEnv());
  await c.loginActors();
  final pass1 = jsonDecode(
    File('${outDir()}/pass1.json').readAsStringSync(),
  ) as Map;
  final liveId = pass1['liveId']?.toString();
  if (liveId == null || liveId.isEmpty) {
    stderr.writeln('no liveId in pass1.json');
    exit(4);
  }
  final hub = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveId&select=id,kind,body,sender_label&order=created_at.asc&limit=80',
    jwt: c.buyerJwt,
  );
  final hubAnon = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$liveId&select=id,kind,body,sender_label&order=created_at.asc&limit=80',
  );
  await dumpJson('${outDir()}/confirm_hub_msgs.json', {
    'liveId': liveId,
    'buyer_http': hub.status,
    'anon_http': hubAnon.status,
    'buyer_n': hub.list.length,
    'anon_n': hubAnon.list.length,
    'buyer_rows': hub.list,
    'anon_rows': hubAnon.list,
  });
  stdout.writeln(
      'hub buyer n=${hub.list.length} anon n=${hubAnon.list.length} live=$liveId');
  for (final row in hub.list) {
    if (row is Map) {
      stdout.writeln('${row['kind']} | ${row['sender_label']} | ${row['body']}');
    }
  }
}
