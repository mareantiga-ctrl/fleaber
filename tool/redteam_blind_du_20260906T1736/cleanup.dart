/// End leftover RTDU lives. Restore S1 hub. No fixes.
import 'dart:io';
import '_rtdu.dart';

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await c.loginActors();
  await c.restoreSeller1Published();

  final h = await c.rest(
    'GET',
    'lives?title=like.${Uri.encodeQueryComponent('$prefix*')}&select=id,title,status,is_active&limit=120',
    service: true,
  );
  stdout.writeln('found ${h.list.length}');
  for (final row in h.list) {
    if (row is Map) {
      final id = row['id']?.toString();
      if (id == null) continue;
      await c.endLive(id);
      stdout.writeln(
          'ended $id ${row['title']} ${row['status']} ${row['is_active']}');
    }
  }
}
