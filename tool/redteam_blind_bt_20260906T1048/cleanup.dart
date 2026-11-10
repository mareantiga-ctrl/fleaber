/// End leftover RTBT lives. No fixes.
import 'dart:io';

import '_rtbt.dart';

Future<void> main() async {
  final c = Rtbt.fromEnv(loadEnv());
  final h = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeComponent('$prefix*')}&select=id,title,status,is_active&limit=50',
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
