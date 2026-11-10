/// End leftover RTCF lives. No fixes.
import 'dart:io';

import '_rtcf.dart';

Future<void> main() async {
  final c = Rtcf.fromEnv(loadEnv());
  final h = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,title,status,is_active&limit=120',
    service: true,
  );
  stdout.writeln('found ${h.brief}');
  for (final row in h.list) {
    if (row is Map) {
      final id = row['id']?.toString();
      if (id == null) continue;
      await c.endLive(id);
      stdout.writeln('ended $id ${row['title']}');
    }
  }
}
